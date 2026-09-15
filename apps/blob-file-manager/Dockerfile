FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates/ templates/

EXPOSE 8080

USER 1000

CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
