# Stage 1: build
FROM python:3.12-slim as builder
WORKDIR /app

# avoid .pyc files, buffer issues
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --upgrade pip \
 && pip install --prefix=/install -r requirements.txt

# Stage 2: final image
FROM python:3.12-slim
WORKDIR /app

# copy installed deps
COPY --from=builder /install /usr/local

# copy app source
COPY . .

# expose port
EXPOSE 8000

# default prod entrypoint
ENTRYPOINT ["gunicorn", "app:app", "--config", "gunicorn.conf.py"]
