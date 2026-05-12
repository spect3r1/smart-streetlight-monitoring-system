from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Query, Request, WebSocket, WebSocketDisconnect, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, RedirectResponse
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from . import models, schemas
from .auth import authenticate_user, create_access_token, decode_token, ensure_default_admin, get_current_user
from .config import get_settings
from .database import Base, SessionLocal, engine, get_db
from .migrations import ensure_runtime_schema
from .services.mqtt_bridge import MQTTBridge
from .services.realtime import RealtimeHub


settings = get_settings()
STATIC_DIR = Path(__file__).parent / "static"


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(bind=engine)
    ensure_runtime_schema()
    with SessionLocal.begin() as session:
        ensure_default_admin(session)

    realtime_hub = RealtimeHub()
    mqtt_bridge = MQTTBridge(realtime_hub)
    mqtt_bridge.start(asyncio.get_running_loop())
    app.state.realtime_hub = realtime_hub
    app.state.mqtt_bridge = mqtt_bridge
    try:
        yield
    finally:
        mqtt_bridge.stop()


app = FastAPI(title=settings.app_name, lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/", include_in_schema=False)
def root_console() -> RedirectResponse:
    return RedirectResponse(url="/console", status_code=status.HTTP_307_TEMPORARY_REDIRECT)


@app.get("/console", include_in_schema=False)
def console_page() -> FileResponse:
    return FileResponse(STATIC_DIR / "console.html")


@app.get("/health")
def health(request: Request) -> dict[str, object]:
    bridge: MQTTBridge = request.app.state.mqtt_bridge
    return {"status": "ok", "mqtt_connected": bridge.is_connected}


@app.post(f"{settings.api_prefix}/auth/login", response_model=schemas.TokenResponse)
def login(payload: schemas.LoginRequest, db: Session = Depends(get_db)) -> schemas.TokenResponse:
    user = authenticate_user(db, payload.username, payload.password)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    token = create_access_token(user.username)
    return schemas.TokenResponse(
        access_token=token,
        expires_in=settings.access_token_expire_minutes * 60,
    )


@app.get(f"{settings.api_prefix}/me", response_model=schemas.UserRead)
def read_me(current_user: models.User = Depends(get_current_user)) -> models.User:
    return current_user


@app.get(f"{settings.api_prefix}/dashboard/summary", response_model=schemas.DashboardSummary)
def dashboard_summary(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> schemas.DashboardSummary:
    window_start = datetime.now(timezone.utc) - timedelta(hours=24)
    total_devices = db.scalar(select(func.count()).select_from(models.Device)) or 0
    online_devices = db.scalar(
        select(func.count()).select_from(models.Device).where(models.Device.last_seen_at.is_not(None))
    ) or 0
    devices_with_faults = db.scalar(
        select(func.count()).select_from(models.Device).where(models.Device.has_fault.is_(True))
    ) or 0
    telemetry_events_last_24h = db.scalar(
        select(func.count())
        .select_from(models.TelemetryEvent)
        .where(models.TelemetryEvent.received_at >= window_start)
    ) or 0
    return schemas.DashboardSummary(
        total_devices=total_devices,
        online_devices=online_devices,
        devices_with_faults=devices_with_faults,
        telemetry_events_last_24h=telemetry_events_last_24h,
    )


@app.get(f"{settings.api_prefix}/devices", response_model=list[schemas.DeviceSummary])
def list_devices(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> list[models.Device]:
    query = select(models.Device).order_by(models.Device.last_seen_at.desc(), models.Device.id.asc())
    return list(db.scalars(query).all())


@app.get(f"{settings.api_prefix}/devices/{{device_id}}", response_model=schemas.DeviceDetail)
def get_device(
    device_id: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> models.Device:
    device = db.get(models.Device, device_id)
    if device is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
    return device


@app.get(f"{settings.api_prefix}/devices/{{device_id}}/telemetry", response_model=list[schemas.TelemetryRead])
def get_device_telemetry(
    device_id: str,
    limit: int = Query(default=50, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> list[models.TelemetryEvent]:
    ensure_device_exists(db, device_id)
    query = (
        select(models.TelemetryEvent)
        .where(models.TelemetryEvent.device_id == device_id)
        .order_by(models.TelemetryEvent.received_at.desc())
        .limit(limit)
    )
    return list(db.scalars(query).all())


@app.get(f"{settings.api_prefix}/devices/{{device_id}}/faults", response_model=list[schemas.FaultRead])
def get_device_faults(
    device_id: str,
    limit: int = Query(default=20, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> list[models.FaultEvent]:
    ensure_device_exists(db, device_id)
    query = (
        select(models.FaultEvent)
        .where(models.FaultEvent.device_id == device_id)
        .order_by(models.FaultEvent.received_at.desc())
        .limit(limit)
    )
    return list(db.scalars(query).all())


@app.get(f"{settings.api_prefix}/devices/{{device_id}}/status", response_model=list[schemas.StatusRead])
def get_device_status(
    device_id: str,
    limit: int = Query(default=20, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> list[models.StatusEvent]:
    ensure_device_exists(db, device_id)
    query = (
        select(models.StatusEvent)
        .where(models.StatusEvent.device_id == device_id)
        .order_by(models.StatusEvent.received_at.desc())
        .limit(limit)
    )
    return list(db.scalars(query).all())


@app.get(f"{settings.api_prefix}/devices/{{device_id}}/commands", response_model=list[schemas.CommandRead])
def get_device_commands(
    device_id: str,
    limit: int = Query(default=20, ge=1, le=200),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> list[models.CommandEvent]:
    ensure_device_exists(db, device_id)
    query = (
        select(models.CommandEvent)
        .where(models.CommandEvent.device_id == device_id)
        .order_by(models.CommandEvent.created_at.desc())
        .limit(limit)
    )
    return list(db.scalars(query).all())


@app.post(
    f"{settings.api_prefix}/devices/{{device_id}}/commands",
    response_model=schemas.CommandRead,
    status_code=status.HTTP_202_ACCEPTED,
)
async def send_device_command(
    device_id: str,
    payload: schemas.DeviceCommandRequest,
    request: Request,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user),
) -> schemas.CommandRead:
    ensure_device_exists(db, device_id)
    bridge: MQTTBridge = request.app.state.mqtt_bridge
    try:
        command_event, envelope = bridge.publish_expected_state(
            device_id=device_id,
            led_expected=payload.model_dump(include={"led1_expected", "led2_expected", "led3_expected"}),
            auto_lights_enabled=payload.auto_lights_enabled,
            auto_light_threshold=payload.auto_light_threshold,
            requested_by=current_user.username,
            note=payload.note,
        )
    except LookupError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found") from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=str(exc)) from exc

    hub: RealtimeHub = request.app.state.realtime_hub
    await hub.broadcast(envelope)
    return command_event


@app.websocket("/ws/stream")
async def websocket_stream(websocket: WebSocket) -> None:
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4401)
        return

    try:
        decode_token(token)
    except HTTPException:
        await websocket.close(code=4401)
        return

    hub: RealtimeHub = websocket.app.state.realtime_hub
    await hub.connect(websocket)
    await websocket.send_json(
        schemas.RealtimeEnvelope(
            type="session.ready",
            device_id=None,
            payload={"message": "Realtime stream connected"},
            timestamp=datetime.now(timezone.utc),
        ).model_dump(mode="json")
    )
    try:
        while True:
            await websocket.receive_text()
    except WebSocketDisconnect:
        await hub.disconnect(websocket)


def ensure_device_exists(db: Session, device_id: str) -> None:
    if db.get(models.Device, device_id) is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Device not found")
