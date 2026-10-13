package com.example.notes;

import java.util.Map;
import java.util.Properties;

import com.zaxxer.hikari.HikariConfig;
import org.junit.jupiter.api.Test;
import org.springframework.boot.context.properties.bind.Binder;
import org.springframework.boot.env.YamlPropertySourceLoader;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.StandardEnvironment;
import org.springframework.core.io.ClassPathResource;

import static org.assertj.core.api.Assertions.assertThat;

class AzureConfigurationTest {
    @Test
    void bindsReleasedPluginOptionsAndRequiresVerifiedTls() throws Exception {
        var environment = new StandardEnvironment();
        environment.getPropertySources().addFirst(new MapPropertySource("test", Map.of(
                "POSTGRES_HOST", "example.postgres.database.azure.com",
                "POSTGRES_USERNAME", "notes-identity",
                "POSTGRES_SSL_ROOT_CERT", "ca.pem",
                "POSTGRES_MANAGED_IDENTITY_ENABLED", "true",
                "AZURE_CLIENT_ID", "managed-identity-client-id",
                "AZURE_TENANT_ID", "tenant-id")));
        var sources = new YamlPropertySourceLoader()
                .load("azure", new ClassPathResource("application-azure.yaml"));
        sources.forEach(source -> environment.getPropertySources().addLast(source));
        var config = Binder.get(environment).bind("spring.datasource.hikari", HikariConfig.class).get();
        Properties properties = config.getDataSourceProperties();
        assertThat(properties.getProperty("currentSchema")).isEqualTo("notes");
        assertThat(properties.getProperty("sslmode")).isEqualTo("verify-full");
        assertThat(properties.getProperty("sslrootcert")).isEqualTo("ca.pem");
        assertThat(properties.getProperty("azure.managedIdentityEnabled")).isEqualTo("true");
        assertThat(properties.getProperty("azure.clientId")).isEqualTo("managed-identity-client-id");
        assertThat(properties.getProperty("azure.tenantId")).isEqualTo("tenant-id");
        var plugin = Class.forName(properties.getProperty("authenticationPluginClassName"));
        assertThat(Class.forName("org.postgresql.plugin.AuthenticationPlugin").isAssignableFrom(plugin)).isTrue();
        assertThat(plugin.getConstructor(Properties.class)).isNotNull();
        assertThat(environment.getProperty("spring.datasource.password")).isEmpty();
        assertThat(environment.getProperty("spring.datasource.username")).isEqualTo("notes-identity");
    }
}
