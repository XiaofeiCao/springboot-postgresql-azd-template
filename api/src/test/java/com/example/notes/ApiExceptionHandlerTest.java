package com.example.notes;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ApiExceptionHandlerTest {
    private final ApiExceptionHandler handler = new ApiExceptionHandler();

    @Test
    void notFoundIsExplicit() {
        assertThat(handler.notFound().getStatus()).isEqualTo(404);
        assertThat(handler.notFound().getDetail()).isEqualTo("Note not found.");
    }

    @Test
    void databaseFailureDoesNotExposeConnectionDetails() {
        assertThat(handler.databaseUnavailable().getStatus()).isEqualTo(503);
        assertThat(handler.databaseUnavailable().getDetail())
                .isEqualTo("The database is temporarily unavailable.");
    }
}
