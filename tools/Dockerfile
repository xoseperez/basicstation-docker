FROM python:alpine3.14
WORKDIR /app
COPY *.py ./
COPY requirements.txt ./
RUN pip install --upgrade pip
RUN pip install -r requirements.txt
