FROM golang:1.18-alpine

EXPOSE 8080

RUN mkdir /app

ADD . /app

WORKDIR /app

RUN go get
RUN go build -o main .

CMD [ "/app/main" ]
