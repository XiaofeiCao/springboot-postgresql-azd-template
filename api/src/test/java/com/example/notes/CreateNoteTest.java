package com.example.notes;

import jakarta.validation.Validation;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class CreateNoteTest {
    @Test
    void validatesRequiredFieldsAndLimits() {
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            var validator = factory.getValidator();
            assertThat(validator.validate(new CreateNote("Title", "Content"))).isEmpty();
            assertThat(validator.validate(new CreateNote(" ", null))).hasSize(2);
            assertThat(validator.validate(new CreateNote("a".repeat(201), "b".repeat(10001)))).hasSize(2);
        }
    }
}
