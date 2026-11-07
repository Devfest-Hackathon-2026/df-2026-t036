FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080
WORKDIR /app
COPY requirements.txt .
# pillow-heif wheels bundle the HEIF decoder; keep image codecs inside the same
# pinned Python environment used locally and on Cloud Run.
RUN pip install --no-cache-dir -r requirements.txt
# 実行ユーザーを分離して、コンテナー内の権限を制限する。
RUN useradd --create-home appuser
COPY --chown=appuser:appuser app ./app
USER appuser
EXPOSE 8080
# Cloud Runから渡されるPORTを展開し、シグナルをUvicornへ直接渡す。
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
