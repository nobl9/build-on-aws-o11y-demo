package main

import (
	"log"
	"math/rand"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	httptrace "gopkg.in/DataDog/dd-trace-go.v1/contrib/net/http"
	"gopkg.in/DataDog/dd-trace-go.v1/ddtrace/tracer"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Count of all HTTP requests",
	}, []string{"code", "method"})

	httpRequestDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name: "http_request_duration_seconds",
		Help: "Duration of all HTTP requests",
	}, []string{"code", "handler", "method"})
)

func getDelay(min int, max int) time.Duration {
	rand.Seed(time.Now().UnixNano())
	r := rand.Intn(max-min+1) + min
	return time.Duration(time.Duration(r) * time.Millisecond)
}

func main() {
	r := prometheus.NewRegistry()
	r.MustRegister(httpRequestsTotal)
	r.MustRegister(httpRequestDuration)

	// Happy path. Fast and returns successfully
	goodHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(100, 500)
		log.Printf("good: delay is %d", delay/time.Millisecond)
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// Small delay but successful
	okHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(200, 800)
		log.Printf("ok: delay is %d", delay/time.Millisecond)
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// Significant delay, but successful
	verySlowHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(500, 2000)
		log.Printf("veryslow: delay is %d", delay/time.Millisecond)
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// No delay, and returns 404
	notfoundHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})

	// Small delay, and returns 500
	errorHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(200, 400)
		log.Printf("error: delay is %d", delay/time.Millisecond)
		time.Sleep(delay)
		w.WriteHeader(http.StatusInternalServerError)
	})

	// Significant delay, and returns 500
	badHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(500, 2000)
		log.Printf("bad: delay is %d", delay/time.Millisecond)
		time.Sleep(delay)
		w.WriteHeader(http.StatusInternalServerError)
	})

	tracer.Start()
	defer tracer.Stop()

	mux := httptrace.NewServeMux()

	mux.Handle("/good", goodHandler)
	mux.Handle("/ok", okHandler)
	mux.Handle("/veryslow", verySlowHandler)
	mux.Handle("/err", errorHandler)
	mux.Handle("/bad", badHandler)
	mux.Handle("/notfound", notfoundHandler)

	srv := &http.Server{Addr: ":8080", Handler: mux}

	log.Fatal(srv.ListenAndServe())
}
