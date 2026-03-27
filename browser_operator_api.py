from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Optional

from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, status
from pydantic import BaseModel

from browser_operator import BrowserOperator, load_settings

load_dotenv()

API_TOKEN = os.environ.get("API_TOKEN", "")


def _require_token(x_api_token: str = Header(default="")) -> None:
    if not API_TOKEN:
        raise HTTPException(status_code=500, detail="API_TOKEN not configured on server")
    if x_api_token != API_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing X-API-Token",
        )


operator: BrowserOperator | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global operator
    settings = load_settings()
    operator = BrowserOperator(settings)
    yield
    for sid in list(operator.sessions.keys()):
        try:
            await operator.close_session(sid)
        except Exception:
            pass


app = FastAPI(title="Generic Browser Operator", version="1.0.0", lifespan=lifespan)


def _op() -> BrowserOperator:
    if operator is None:
        raise RuntimeError("Operator not initialised")
    return operator


class SessionIdBody(BaseModel):
    session_id: str

class OpenBody(BaseModel):
    session_id: str
    url: str

class ClickBody(BaseModel):
    session_id: str
    selector: Optional[str] = None
    text: Optional[str] = None
    index: Optional[int] = None

class TypeBody(BaseModel):
    session_id: str
    selector: str
    text: str

class PressBody(BaseModel):
    session_id: str
    key: str

class WaitBody(BaseModel):
    session_id: str
    ms: int = 1000


@app.get("/health")
async def health():
    return {"ok": True, "service": "generic-browser-operator"}


@app.post("/session/start")
async def session_start(x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().start_session()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/close")
async def session_close(body: SessionIdBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().close_session(body.session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/open")
async def session_open(body: OpenBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().open_url(body.session_id, body.url)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/click")
async def session_click(body: ClickBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().click(body.session_id, body.selector, body.text, body.index)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/type")
async def session_type(body: TypeBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().type_text(body.session_id, body.selector, body.text)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/press")
async def session_press(body: PressBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().press_key(body.session_id, body.key)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/wait")
async def session_wait(body: WaitBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().wait_ms(body.session_id, body.ms)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/read")
async def session_read(body: SessionIdBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().read_page(body.session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/screenshot")
async def session_screenshot(body: SessionIdBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().screenshot(body.session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/session/list-clickable")
async def session_list_clickable(body: SessionIdBody, x_api_token: str = Header(default="")):
    _require_token(x_api_token)
    try:
        return await _op().list_clickable(body.session_id)
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
