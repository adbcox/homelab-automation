FROM mcr.microsoft.com/playwright/python:v1.52.0-jammy

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app

RUN mkdir -p /app/artifacts /app/playwright/.auth

EXPOSE 8010

CMD ["uvicorn", "api_server:app", "--host", "0.0.0.0", "--port", "8010"]
