package cl.duocuc.ep03;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class DemoApplicationTest {

    @Test
    void contextLoads() {
        // Verifica que el contexto de Spring Boot levanta sin excepciones
        assertDoesNotThrow(() -> {}, "El contexto de Spring Boot debe levantar correctamente");
    }

    // main() se omite del test — arranca una app real sin perfil test
    // lo que causa SchemaManagementException al no tener PostgreSQL en CI
}
