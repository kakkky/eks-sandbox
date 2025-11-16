package main

import (
	"html/template"
	"log"
	"net/http"
	"sync"
)

type Todo struct {
	Title string
}

var todos []Todo
var mu sync.Mutex
var tmpl = template.Must(template.ParseFiles("index.html"))

func getTodoHandler(w http.ResponseWriter, r *http.Request) {
	tmpl.Execute(w, todos)
}

func postTodoHandler(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Failed to parse form", http.StatusBadRequest)
		return
	}
	title := r.FormValue("title")
	if title != "" {
		mu.Lock()
		todos = append(todos, Todo{Title: title})
		mu.Unlock()
	}
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("%s %s %s", r.RemoteAddr, r.Method, r.URL)
		next.ServeHTTP(w, r)
	})
}

func main() {
	http.Handle("GET /", logger(http.HandlerFunc(getTodoHandler)))
	http.Handle("POST /", logger(http.HandlerFunc(postTodoHandler)))

	http.ListenAndServe(":8080", nil)
}
