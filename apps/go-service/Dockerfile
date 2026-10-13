FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod .
COPY main.go .
RUN go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
