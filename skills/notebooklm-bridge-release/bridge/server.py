#!/usr/bin/env python3
"""
NotebookLM HTTP Bridge
把 notebooklm CLI 完整透传为 HTTP 接口，远程 agent 像调用本地 CLI 一样使用。

端点：
  POST /run            同步执行（适合 <60s 的命令）
  POST /run/async      异步执行，立即返回 job_id
  GET  /jobs/{job_id}  查询 job 状态/结果
  GET  /jobs           列出最近 100 个 job
  DELETE /jobs/{job_id} 取消正在运行的 job
  GET  /health         健康检查

认证：所有写操作需要 Header: X-Token: <token>
      token 来自环境变量 NOTEBOOKLM_BRIDGE_TOKEN 或 HERMES_WEBHOOK_TOKEN
"""

import os
import shutil
import subprocess
import threading
import time
import uuid
from collections import OrderedDict
from pathlib import Path
from typing import Optional

import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

# ── 配置 ─────────────────────────────────────────────────────────────────────

HOST  = os.environ.get("NOTEBOOKLM_BRIDGE_HOST", "localhost")
PORT  = int(os.environ.get("NOTEBOOKLM_BRIDGE_PORT", 18800))
TOKEN = (
    os.environ.get("NOTEBOOKLM_BRIDGE_TOKEN")
    or os.environ.get("HERMES_WEBHOOK_TOKEN")
    or os.environ.get("HERMES_SOP_SECRET")
    or ""
)
SYNC_TIMEOUT  = int(os.environ.get("NOTEBOOKLM_BRIDGE_SYNC_TIMEOUT", 60))
MAX_JOBS      = int(os.environ.get("NOTEBOOKLM_BRIDGE_MAX_JOBS", 200))
OUTPUT_LIMIT  = 512 * 1024  # stdout/stderr 各最多 512KB 存内存


def _find_notebooklm() -> str:
    for candidate in [
        shutil.which("notebooklm"),
        str(Path.home() / ".local/bin/notebooklm"),
        str(Path.home() / ".venvs/notebooklm-py/bin/notebooklm"),
    ]:
        if candidate and Path(candidate).exists():
            return candidate
    return "notebooklm"


NOTEBOOKLM_BIN = _find_notebooklm()

# ── Job 存储 ──────────────────────────────────────────────────────────────────

_jobs: OrderedDict[str, dict] = OrderedDict()
_jobs_lock = threading.Lock()


def _new_job(args: list[str]) -> dict:
    return {
        "job_id":      str(uuid.uuid4()),
        "status":      "pending",   # pending | running | done | failed | cancelled
        "args":        args,
        "exit_code":   None,
        "stdout":      "",
        "stderr":      "",
        "started_at":  None,
        "finished_at": None,
        "pid":         None,
    }


def _save_job(job: dict) -> None:
    with _jobs_lock:
        _jobs[job["job_id"]] = job
        # 超出上限时删最老的
        while len(_jobs) > MAX_JOBS:
            _jobs.popitem(last=False)


def _get_job(job_id: str) -> Optional[dict]:
    with _jobs_lock:
        return _jobs.get(job_id)


# ── CLI 执行 ──────────────────────────────────────────────────────────────────

def _run_cli(args: list[str], timeout: Optional[int] = None) -> dict:
    """执行 notebooklm CLI，返回 {exit_code, stdout, stderr}"""
    cmd = [NOTEBOOKLM_BIN] + args
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "exit_code": result.returncode,
            "stdout":    result.stdout[:OUTPUT_LIMIT],
            "stderr":    result.stderr[:OUTPUT_LIMIT],
        }
    except subprocess.TimeoutExpired:
        return {"exit_code": 124, "stdout": "", "stderr": f"timed out after {timeout}s"}
    except FileNotFoundError:
        return {"exit_code": 127, "stdout": "", "stderr": f"notebooklm not found: {NOTEBOOKLM_BIN}"}
    except Exception as e:
        return {"exit_code": 1, "stdout": "", "stderr": str(e)}


def _run_job_background(job: dict) -> None:
    """后台线程：执行 CLI 并更新 job 状态"""
    with _jobs_lock:
        job["status"]     = "running"
        job["started_at"] = time.time()

    cmd = [NOTEBOOKLM_BIN] + job["args"]
    proc = None
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        with _jobs_lock:
            job["pid"] = proc.pid

        stdout, stderr = proc.communicate()

        with _jobs_lock:
            if job["status"] == "cancelled":
                return
            job["exit_code"]   = proc.returncode
            job["stdout"]      = stdout[:OUTPUT_LIMIT]
            job["stderr"]      = stderr[:OUTPUT_LIMIT]
            job["status"]      = "done" if proc.returncode == 0 else "failed"
            job["finished_at"] = time.time()

    except Exception as e:
        with _jobs_lock:
            job["status"]      = "failed"
            job["stderr"]      = str(e)
            job["finished_at"] = time.time()
    finally:
        if proc and proc.poll() is None:
            try:
                proc.kill()
            except Exception:
                pass


# ── FastAPI ───────────────────────────────────────────────────────────────────

app = FastAPI(
    title="NotebookLM HTTP Bridge",
    description="Transparent HTTP proxy for the notebooklm CLI",
    version="1.0.0",
)


def _verify_token(request: Request) -> None:
    if not TOKEN:
        return
    client_token = request.headers.get("X-Token", "")
    if client_token != TOKEN:
        raise HTTPException(status_code=401, detail="invalid token")


class RunRequest(BaseModel):
    args: list[str]


class AsyncRunRequest(BaseModel):
    args: list[str]


# ── 端点 ──────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status": "ok",
        "notebooklm_bin": NOTEBOOKLM_BIN,
        "notebooklm_found": Path(NOTEBOOKLM_BIN).exists(),
        "active_jobs": sum(1 for j in _jobs.values() if j["status"] == "running"),
    }


@app.post("/run")
def run_sync(body: RunRequest, _: None = Depends(_verify_token)):
    """
    同步执行 notebooklm CLI 命令，阻塞直到完成。
    适合快速命令（list/create/source add/auth check 等），超时 60s。

    示例：
      {"args": ["source", "add", "https://youtube.com/...", "-n", "NB_ID", "--json"]}
    """
    result = _run_cli(body.args, timeout=SYNC_TIMEOUT)
    return JSONResponse(content=result, status_code=200 if result["exit_code"] == 0 else 422)


@app.post("/run/async")
def run_async(body: AsyncRunRequest, _: None = Depends(_verify_token)):
    """
    异步执行命令，立即返回 job_id。
    适合耗时命令（source wait / artifact wait / generate / download）。

    示例：
      {"args": ["artifact", "wait", "TASK_ID", "-n", "NB_ID", "--timeout", "900"]}

    返回：{"job_id": "uuid", "status": "pending"}
    """
    job = _new_job(body.args)
    _save_job(job)
    t = threading.Thread(target=_run_job_background, args=(job,), daemon=True)
    t.start()
    return {"job_id": job["job_id"], "status": job["status"]}


@app.get("/jobs/{job_id}")
def get_job(job_id: str, _: None = Depends(_verify_token)):
    """
    查询 job 状态。
    status: pending | running | done | failed | cancelled
    done/failed 时包含 exit_code / stdout / stderr。
    """
    job = _get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return _job_response(job)


@app.get("/jobs")
def list_jobs(_: None = Depends(_verify_token)):
    """列出最近的 jobs（不含 stdout/stderr，只看状态）"""
    with _jobs_lock:
        jobs = list(_jobs.values())
    return {
        "total": len(jobs),
        "jobs": [
            {
                "job_id":      j["job_id"],
                "status":      j["status"],
                "args":        j["args"],
                "exit_code":   j["exit_code"],
                "started_at":  j["started_at"],
                "finished_at": j["finished_at"],
            }
            for j in reversed(jobs)
        ],
    }


@app.delete("/jobs/{job_id}")
def cancel_job(job_id: str, _: None = Depends(_verify_token)):
    """取消正在运行的 job（发送 SIGKILL）"""
    job = _get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    with _jobs_lock:
        if job["status"] not in ("pending", "running"):
            return {"job_id": job_id, "status": job["status"], "message": "already finished"}
        job["status"] = "cancelled"
        pid = job.get("pid")

    if pid:
        try:
            import signal
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    return {"job_id": job_id, "status": "cancelled"}


def _job_response(job: dict) -> dict:
    resp = {k: job[k] for k in ("job_id", "status", "args", "exit_code", "started_at", "finished_at", "pid")}
    if job["status"] in ("done", "failed", "cancelled"):
        resp["stdout"] = job["stdout"]
        resp["stderr"] = job["stderr"]
    return resp


# ── 启动 ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"[bridge] notebooklm bin: {NOTEBOOKLM_BIN}")
    print(f"[bridge] token auth:     {'enabled' if TOKEN else 'DISABLED (no token set)'}")
    print(f"[bridge] listening on:   {HOST}:{PORT}")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
