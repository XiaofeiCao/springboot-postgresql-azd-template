package com.example.notes;

import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(NoteNotFoundException.class)
    public ProblemDetail notFound() {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "Note not found.");
    }

    @ExceptionHandler(DataAccessException.class)
    public ProblemDetail databaseUnavailable() {
        return ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE,
                "The database is temporarily unavailable.");
    }
}
