FROM golang:1.25-bookworm

WORKDIR /app

COPY . .

RUN go build -o todo-app main.go

CMD ["./todo-app"]