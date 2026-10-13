package com.example.notes;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.UUID;

import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;
import tools.jackson.databind.ObjectMapper;

import static org.assertj.core.api.Assertions.assertThat;

@Testcontainers
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class NotesApiIT {
    @Container
    static final PostgreSQLContainer POSTGRES = new PostgreSQLContainer("postgres:17.6-alpine")
            .withInitScript("test-schema.sql");

    @DynamicPropertySource
    static void database(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", POSTGRES::getJdbcUrl);
        registry.add("spring.datasource.username", POSTGRES::getUsername);
        registry.add("spring.datasource.password", POSTGRES::getPassword);
        registry.add("spring.datasource.hikari.data-source-properties.currentSchema", () -> "notes");
    }

    @LocalServerPort
    private int port;

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private ObjectMapper mapper;

    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    @Test
    @Order(1)
    void createsReadsAndListsPersistedNotes() throws Exception {
        assertThat(jdbc.queryForObject("SELECT current_schema()", String.class)).isEqualTo("notes");
        var created = post("""
                {"title":"Persistent note","content":"Don't interpolate ' SQL"}
                """);
        assertThat(created.statusCode()).isEqualTo(201);
        var body = mapper.readTree(created.body());
        String id = body.get("id").asText();
        String location = created.headers().firstValue("Location").orElseThrow();
        assertThat(location).isEqualTo("/notes/" + id);
        assertThat(get(location).body()).isEqualTo(created.body());
        assertThat(mapper.readTree(get("/notes").body()).toString()).contains(id);
        assertThat(jdbc.queryForObject("SELECT content FROM notes WHERE id = ?", String.class,
                UUID.fromString(id))).isEqualTo("Don't interpolate ' SQL");
        new ResourceDatabasePopulator(new ClassPathResource("schema.sql")).execute(jdbc.getDataSource());
        assertThat(get(location).statusCode()).isEqualTo(200);
    }

    @Test
    @Order(2)
    void rejectsInvalidInputAndReportsNotFound() throws Exception {
        assertThat(post("{\"title\":\" \",\"content\":\"hello\"}").statusCode()).isEqualTo(400);
        assertThat(post("{\"title\":\"hello\"}").statusCode()).isEqualTo(400);
        assertThat(post(mapper.writeValueAsString(new CreateNote("a".repeat(201), "content")))
                .statusCode()).isEqualTo(400);
        assertThat(post(mapper.writeValueAsString(new CreateNote("title", "b".repeat(10001))))
                .statusCode()).isEqualTo(400);
        assertThat(post("{broken").statusCode()).isEqualTo(400);
        assertThat(get("/notes/not-a-uuid").statusCode()).isEqualTo(400);
        var missing = get("/notes/" + UUID.randomUUID());
        assertThat(missing.statusCode()).isEqualTo(404);
        assertThat(mapper.readTree(missing.body()).get("detail").asText()).isEqualTo("Note not found.");
    }

    @Test
    @Order(3)
    void exposesLivenessAndDatabaseAwareReadiness() throws Exception {
        assertThat(get("/actuator/health/liveness").statusCode()).isEqualTo(200);
        var readiness = get("/actuator/health/readiness");
        assertThat(readiness.statusCode()).isEqualTo(200);
        assertThat(mapper.readTree(readiness.body()).get("status").asText()).isEqualTo("UP");
        assertThat(get("/actuator/env").statusCode()).isEqualTo(404);
    }

    @Test
    @Order(4)
    void databaseOutageMakesReadinessFailButNotLiveness() throws Exception {
        POSTGRES.stop();
        var readiness = get("/actuator/health/readiness");
        assertThat(readiness.statusCode()).isEqualTo(503);
        assertThat(mapper.readTree(readiness.body()).get("status").asText()).isEqualTo("DOWN");
        assertThat(get("/actuator/health/liveness").statusCode()).isEqualTo(200);
        var unavailable = get("/notes");
        assertThat(unavailable.statusCode()).isEqualTo(503);
        assertThat(unavailable.body()).doesNotContain("jdbc:", POSTGRES.getPassword(), "SQLException");
    }

    private HttpResponse<String> get(String path) throws Exception {
        return http.send(HttpRequest.newBuilder(uri(path)).timeout(Duration.ofSeconds(15)).GET().build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String body) throws Exception {
        return http.send(HttpRequest.newBuilder(uri("/notes")).timeout(Duration.ofSeconds(15))
                .header("Content-Type", "application/json").POST(HttpRequest.BodyPublishers.ofString(body)).build(),
                HttpResponse.BodyHandlers.ofString());
    }

    private URI uri(String path) {
        return URI.create("http://localhost:" + port + path);
    }
}
