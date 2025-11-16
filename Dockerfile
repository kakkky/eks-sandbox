FROM golang:1.25-bookworm

WORKDIR /src

COPY . .

WORKDIR /src/app

RUN go build -o todo-app main.go

CMD ["./todo-app"]