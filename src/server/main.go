package main

import (
	"log"
	"math/rand"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
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
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// Small delay but successful
	okHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(500, 800)
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// Significant delay, but successful
	verySlowHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(800, 2000)
		time.Sleep(delay)
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte("Hello from example application."))
		if err != nil {
			log.Printf("Write failed: %v", err)
		}
	})

	// After a reasonable delay returns a successful response ~90% of the time.
	// Otherwise, returns an error response (500)
	acceptableHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(200, 1000)
		time.Sleep(delay)

		// roll the dice and see if we return an error
		rand.Seed(time.Now().UnixNano())
		rand.Intn(100)

		if rand.Intn(100) > 10 {
			w.WriteHeader(http.StatusOK)
			_, err := w.Write([]byte("Hello from example application."))
			if err != nil {
				log.Printf("Write failed: %v", err)
			}
		} else {
			w.WriteHeader(http.StatusInternalServerError)
		}
	})

	// No delay, and returns 404
	notfoundHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	})

	// Small delay, and returns 500
	errorHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(200, 400)
		time.Sleep(delay)
		w.WriteHeader(http.StatusInternalServerError)
	})

	// Significant delay, and returns 500
	badHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delay := getDelay(500, 2000)
		time.Sleep(delay)
		w.WriteHeader(http.StatusInternalServerError)
	})

	mux := http.NewServeMux()
	mux.Handle("/good",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "good"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, goodHandler),
		),
	)
	mux.Handle("/ok",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "ok"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, okHandler),
		),
	)
	mux.Handle("/acceptable",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "acceptable"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, acceptableHandler),
		),
	)
	mux.Handle("/veryslow",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "veryslow"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, verySlowHandler),
		),
	)
	mux.Handle("/err",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "err"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, errorHandler),
		),
	)
	mux.Handle("/bad",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "bad"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, badHandler),
		),
	)
	mux.Handle("/notfound",
		promhttp.InstrumentHandlerDuration(
			httpRequestDuration.MustCurryWith(prometheus.Labels{"handler": "not-found"}),
			promhttp.InstrumentHandlerCounter(httpRequestsTotal, notfoundHandler),
		),
	)
	mux.Handle("/metrics", promhttp.HandlerFor(r, promhttp.HandlerOpts{}))

	srv := &http.Server{Addr: ":8080", Handler: mux}

	log.Fatal(srv.ListenAndServe())
}
