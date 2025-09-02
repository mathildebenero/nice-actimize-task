FROM python:3.11-slim
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ .
EXPOSE 8080
# Container-level readiness probe (hits the internal port 8080)
HEALTHCHECK --interval=3s --timeout=2s --start-period=1s --retries=10 \
  CMD python -c "import urllib.request,sys; \
    sys.exit(0) if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=1).getcode()<500 else sys.exit(1)"
CMD ["python", "app.py"]