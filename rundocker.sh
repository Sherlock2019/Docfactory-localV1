docker build -t docfactory:latest .
docker run -d -p 8000:8000 --name docfactory docfactory:latest
