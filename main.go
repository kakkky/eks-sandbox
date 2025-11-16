package main

import (
	"html/template"
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

func main() {
	http.HandleFunc("GET /", getTodoHandler)
	http.HandleFunc("POST /", postTodoHandler)
	http.ListenAndServe(":8080", nil)
}
