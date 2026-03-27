"""
Gateway Health Service — Unified monitoring for all VCS AI Agents.
──────────────────────────────────────────────────────────────────────────────
Port: 8005 | Prefix: /gateway/

Provides a single endpoint to check the health of ALL agents.
Polls each agent's /health endpoint and reports combined status.

Endpoints:
    GET /         — System overview
    GET /health   — All agents health summary
    GET /agents   — Detailed agent registry + status
    GET /info     — System info (uptime, version)
"""

import os
import time
import logging
import asyncio
from datetime import datetime, timezone

import httpx
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
)
logger = logging.getLogger("gateway")

# ── Agent Registry ───────────────────────────────────────────────────────────
#  Add new agents here when they are deployed.
#  Each agent needs: name, internal URL, health path, description.

AGENTS = {
    "rag": {
        "name": "RAG Agent",
        "url": "http://127.0.0.1:8001",
        "health_path": "/health",
        "port": 8001,
        "prefix": "/rag/",
        "description": "Construction Documentation QA — RAG, Web, Hybrid search",
    },
    "sql": {
        "name": "SQL Intelligence Agent",
        "url": "http://127.0.0.1:8002",
        "health_path": "/health",
        "port": 8002,
        "prefix": "/sql/",
        "description": "Natural language to SQL — RFI, Submittal, BIM queries",
    },
    "construction": {
        "name": "Construction Intelligence Agent",
        "url": "http://127.0.0.1:8003",
        "health_path": "/health",
        "port": 8003,
        "prefix": "/construction/",
        "description": "Scope/Exhibit document generation with trade analysis",
    },
    "ingestion": {
        "name": "Ingestion API",
        "url": "http://127.0.0.1:8004",
        "health_path": "/health",
        "port": 8004,
        "prefix": "/ingestion/",
        "description": "FAISS index ingestion pipeline (MongoDB + SQL → embeddings)",
    },
    "docqa": {
        "name": "Document Q&A Agent",
        "url": "http://127.0.0.1:8006",
        "health_path": "/health",
        "port": 8006,
        "prefix": "/docqa/",
        "description": "Upload documents and ask questions — RAG with per-session FAISS",
    },
}

# ── App ──────────────────────────────────────────────────────────────────────
START_TIME = time.time()

app = FastAPI(
    title="VCS Gateway Health Service",
    description="Unified monitoring dashboard for all VCS AI Agents.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "https://ai.ifieldsmart.com,https://ai5.ifieldsmart.com,http://localhost:3000,http://localhost:8501").split(","),
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health Check Helper ──────────────────────────────────────────────────────

async def check_agent_health(agent_id: str, agent_config: dict) -> dict:
    """Check a single agent's health via HTTP."""
    url = f"{agent_config['url']}{agent_config['health_path']}"
    result = {
        "agent_id": agent_id,
        "name": agent_config["name"],
        "url": url,
        "port": agent_config["port"],
        "prefix": agent_config["prefix"],
        "description": agent_config["description"],
    }

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url)
            result["status"] = "healthy" if response.status_code == 200 else "unhealthy"
            result["http_code"] = response.status_code
            try:
                result["details"] = response.json()
            except Exception:
                result["details"] = None
    except httpx.ConnectError:
        result["status"] = "offline"
        result["http_code"] = None
        result["details"] = None
    except httpx.TimeoutException:
        result["status"] = "timeout"
        result["http_code"] = None
        result["details"] = None
    except Exception as e:
        result["status"] = "error"
        result["http_code"] = None
        result["details"] = str(e)

    return result


# ── Endpoints ────────────────────────────────────────────────────────────────

@app.get("/")
async def root():
    """System overview — landing page."""
    return {
        "name": "VCS AI Agents Gateway",
        "version": "1.0.0",
        "agents_registered": len(AGENTS),
        "public_port": 8000,
        "endpoints": {
            "health": "GET /health — All agents health summary",
            "agents": "GET /agents — Detailed agent registry",
            "info": "GET /info — System uptime and version",
        },
        "agent_prefixes": {
            agent_id: config["prefix"]
            for agent_id, config in AGENTS.items()
        },
    }


@app.get("/health")
async def health():
    """
    Combined health check for ALL registered agents.

    Returns overall status:
      - "all_healthy" — every agent responds 200
      - "degraded"    — some agents are down
      - "all_down"    — no agents responding
    """
    tasks = [
        check_agent_health(agent_id, config)
        for agent_id, config in AGENTS.items()
    ]
    results = await asyncio.gather(*tasks)

    healthy_count = sum(1 for r in results if r["status"] == "healthy")
    total = len(results)

    if healthy_count == total:
        overall = "all_healthy"
    elif healthy_count == 0:
        overall = "all_down"
    else:
        overall = "degraded"

    return {
        "status": overall,
        "healthy": healthy_count,
        "total": total,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "agents": {r["agent_id"]: r["status"] for r in results},
        "details": results,
    }


@app.get("/agents")
async def agents():
    """Detailed agent registry with live status."""
    tasks = [
        check_agent_health(agent_id, config)
        for agent_id, config in AGENTS.items()
    ]
    results = await asyncio.gather(*tasks)

    return {
        "agents_registered": len(AGENTS),
        "agents": results,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/info")
async def info():
    """System information."""
    uptime_seconds = time.time() - START_TIME
    hours = int(uptime_seconds // 3600)
    minutes = int((uptime_seconds % 3600) // 60)

    return {
        "gateway_version": "1.0.0",
        "uptime": f"{hours}h {minutes}m",
        "uptime_seconds": round(uptime_seconds),
        "started_at": datetime.fromtimestamp(START_TIME, timezone.utc).isoformat(),
        "agents_registered": len(AGENTS),
        "public_port": 8000,
        "agent_ports": {
            agent_id: config["port"]
            for agent_id, config in AGENTS.items()
        },
    }


# ── Entry point ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    port = int(os.getenv("GATEWAY_PORT", "8005"))
    host = os.getenv("GATEWAY_HOST", "0.0.0.0")

    logger.info(f"Starting Gateway Health Service on {host}:{port}")
    uvicorn.run(app, host=host, port=port)
