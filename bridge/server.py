#!/usr/bin/env python3
"""
NotebookLM HTTP Bridge
把 notebooklm CLI 完整透传为 HTTP 接口，远程 agent 像调用本地 CLI 一样使用。

端点：
  POST /run              同步执行（适合 <60s 的命令）
  POST /run/async        异步执行，立即返回 job_id
  GET  /jobs/{job_id}    查询 job 状态/结果（download 类命令完成后含 r2_urls）
  GET  /jobs             列出最近 job
  DELETE /jobs/{job_id}  取消正在运行的 job
  GET  /health           健康检查

文件传输：
  音频/视频/PDF 等二进制产物通过 R2 传递，不走隧道。
  download 命令完成后自动上传到 R2，job 结果中返回 r2_urls: {filename: url}。
  消费者直接 curl R2 地址下载，无需任何额外接口。

认证：所有写操作需要 Header: X-Token: <token>
      token 来自环境变量 NOTEBOOKLM_BRIDGE_TOKEN 或 HERMES_WEBHOOK_TOKEN
"""

import json
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
OUTPUT_LIMIT  = 512 * 1024  # stdout/stderr 各最多 512KB

STATE_DIR     = Path(os.environ.get("NOTEBOOKLM_BRIDGE_HOME", Path.home() / ".notebooklm-bridge"))
DOWNLOADS_DIR = STATE_DIR / "downloads"
DOWNLOADS_DIR.mkdir(parents=True, exist_ok=True)

# ── R2 上传配置 ───────────────────────────────────────────────────────────────

UPLOAD_R2_URL    = os.environ.get("UPLOAD_R2_URL",    "https://upload-r2.vyibc.com")
UPLOAD_R2_TOKEN  = os.environ.get("UPLOAD_R2_TOKEN",  "yt-research-token-2026")
UPLOAD_R2_DOMAIN = os.environ.get("UPLOAD_R2_DOMAIN", "https://skill.vyibc.com")
UPLOAD_R2_PATH   = os.environ.get("UPLOAD_R2_PATH",   "notebooklm/downloads")

# 需要走 R2 的二进制文件类型
BINARY_EXTS = {".mp3", ".mp4", ".m4a", ".wav", ".ogg", ".webm", ".mov", ".avi", ".pdf", ".zip"}


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

# ── R2 上传 ───────────────────────────────────────────────────────────────────

def _upload_to_r2(file_path: Path) -> Optional[str]:
    """上传文件到 R2，返回公网 URL；失败返回 None。"""
    try:
        result = subprocess.run([
            "curl", "-fsS", "--location", UPLOAD_R2_URL,
            "--header", f"Authorization: Bearer {UPLOAD_R2_TOKEN}",
            "--form", f"file=@{file_path}",
            "--form", f"domain={UPLOAD_R2_DOMAIN}",
            "--form", f"name={file_path.name}",
            "--form", f"path={UPLOAD_R2_PATH}",
        ], capture_output=True, text=True, timeout=300)
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return data.get("image_url")
    except Exception:
        pass
    return None

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
        "r2_urls":     {},          # {filename: r2_url}，download 命令完成后自动填充
        "started_at":  None,
        "finished_at": None,
        "pid":         None,
    }


def _save_job(job: dict) -> None:
    with _jobs_lock:
        _jobs[job["job_id"]] = job
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
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
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
    """后台线程：执行 CLI，完成后自动上传二进制产物到 R2。"""
    with _jobs_lock:
        job["status"]     = "running"
        job["started_at"] = time.time()

    # download 命令自动注入 --output-dir，确保文件写到 downloads 目录
    args = list(job["args"])
    if args and args[0] == "download" and "--output-dir" not in args and "-o" not in args:
        args += ["--output-dir", str(DOWNLOADS_DIR)]
        with _jobs_lock:
            job["args"] = args

    # 记录执行前 downloads 目录快照，用于发现新增文件
    files_before = set(DOWNLOADS_DIR.iterdir()) if DOWNLOADS_DIR.exists() else set()

    cmd = [NOTEBOOKLM_BIN] + args
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

        # 成功后检查 downloads 目录新增文件，二进制类型自动上传 R2
        if proc.returncode == 0 and DOWNLOADS_DIR.exists():
            files_after  = set(DOWNLOADS_DIR.iterdir())
            new_files    = [f for f in (files_after - files_before) if f.is_file()]
            r2_urls      = {}
            for f in new_files:
                if f.suffix.lower() in BINARY_EXTS:
                    url = _upload_to_r2(f)
                    if url:
                        r2_urls[f.name] = url
            if r2_urls:
                with _jobs_lock:
                    job["r2_urls"] = r2_urls

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
    version="1.1.0",
)


def _verify_token(request: Request) -> None:
    if not TOKEN:
        return
    if request.headers.get("X-Token", "") != TOKEN:
        raise HTTPException(status_code=401, detail="invalid token")


class RunRequest(BaseModel):
    args: list[str]


class AsyncRunRequest(BaseModel):
    args: list[str]


# ── 端点 ──────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    return {
        "status":           "ok",
        "notebooklm_bin":   NOTEBOOKLM_BIN,
        "notebooklm_found": Path(NOTEBOOKLM_BIN).exists(),
        "active_jobs":      sum(1 for j in _jobs.values() if j["status"] == "running"),
    }


@app.post("/run")
def run_sync(body: RunRequest, _: None = Depends(_verify_token)):
    """同步执行，阻塞直到完成（60s 超时）。适合 list/create/ask/source add 等快速命令。"""
    result = _run_cli(body.args, timeout=SYNC_TIMEOUT)
    return JSONResponse(content=result, status_code=200 if result["exit_code"] == 0 else 422)


@app.post("/run/async")
def run_async(body: AsyncRunRequest, _: None = Depends(_verify_token)):
    """
    异步执行，立即返回 job_id。适合耗时命令（generate / download / artifact wait）。
    download 命令完成后 job 结果中自动包含 r2_urls: {filename: url}，消费者直接 curl URL 下载。
    """
    job = _new_job(body.args)
    _save_job(job)
    threading.Thread(target=_run_job_background, args=(job,), daemon=True).start()
    return {"job_id": job["job_id"], "status": job["status"]}


@app.get("/jobs/{job_id}")
def get_job(job_id: str, _: None = Depends(_verify_token)):
    """
    查询 job 状态和结果。
    status: pending | running | done | failed | cancelled
    download 命令完成后包含 r2_urls: {"file.mp3": "https://skill.vyibc.com/..."}
    """
    job = _get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="job not found")
    return _job_response(job)


@app.get("/jobs")
def list_jobs(_: None = Depends(_verify_token)):
    """列出最近的 jobs（不含 stdout/stderr）"""
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
                "r2_urls":     j.get("r2_urls", {}),
                "started_at":  j["started_at"],
                "finished_at": j["finished_at"],
            }
            for j in reversed(jobs)
        ],
    }


@app.delete("/jobs/{job_id}")
def cancel_job(job_id: str, _: None = Depends(_verify_token)):
    """取消正在运行的 job（SIGKILL）"""
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
    resp = {k: job[k] for k in ("job_id", "status", "args", "exit_code", "r2_urls", "started_at", "finished_at", "pid")}
    if job["status"] in ("done", "failed", "cancelled"):
        resp["stdout"] = job["stdout"]
        resp["stderr"] = job["stderr"]
    return resp


# ── 启动 ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"[bridge] notebooklm bin: {NOTEBOOKLM_BIN}")
    print(f"[bridge] token auth:     {'enabled' if TOKEN else 'DISABLED'}")
    print(f"[bridge] downloads dir:  {DOWNLOADS_DIR}")
    print(f"[bridge] r2 upload:      {UPLOAD_R2_DOMAIN}/{UPLOAD_R2_PATH}/")
    print(f"[bridge] listening on:   {HOST}:{PORT}")
    uvicorn.run(app, host=HOST, port=PORT, log_level="info")
