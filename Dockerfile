FROM golang:1.21 as build 
WORKDIR /app
COPY ./catgpt /app
RUN cd /app && go mod download && \
CGO_ENABLED=0 go build -o /app/catgpt 

FROM gcr.io/distroless/static-debian12:latest-amd64 as prod
COPY --from=build /app/catgpt /catgpt
CMD ["./catgpt"]
