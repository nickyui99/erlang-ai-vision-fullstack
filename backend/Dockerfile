FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app

COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

COPY backend/app /app/app
COPY backend/alembic.ini /app/alembic.ini

# Demo simulation frames (Option A): kept out of git and generated locally by
# scripts/extract_demo_frames.py, then shipped in the image. mkdir first so the
# build stays green even when the folder is empty/absent. Enable at runtime with
# DEMO_SIMULATION_ENABLED=true.
RUN mkdir -p /app/demo_frames
COPY data/demo_frames/ /app/demo_frames/
ENV DEMO_FRAMES_DIR=/app/demo_frames

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
