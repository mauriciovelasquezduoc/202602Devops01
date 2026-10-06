package cl.duocuc.ep03.cucumber;

import static org.junit.jupiter.api.Assertions.*;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.*;

import com.fasterxml.jackson.databind.ObjectMapper;

import cl.duocuc.ep03.domain.Alumno;
import io.cucumber.java.Before;
import io.cucumber.java.en.And;
import io.cucumber.java.en.Given;
import io.cucumber.java.en.Then;
import io.cucumber.java.en.When;

public class AlumnoSteps extends CucumberSpringConfiguration {

    @Autowired private TestRestTemplate restTemplate;

    @Autowired private ObjectMapper objectMapper;

    private ResponseEntity<?> lastResponse;
    private Long lastCreatedId;

    private String baseUrl() {
        return "http://localhost:" + port + "/ep03";
    }

    @Before
    public void limpiarEstado() {
        lastResponse = null;
        lastCreatedId = null;
    }

    // ─── GIVEN ───────────────────────────────────────────────────────────────

    @Given("la aplicacion esta en ejecucion")
    public void laAplicacionEstaEnEjecucion() {
        ResponseEntity<String> ping = restTemplate.getForEntity(baseUrl(), String.class);
        assertTrue(ping.getStatusCode().is2xxSuccessful(), "La aplicacion debe estar corriendo");
    }

    @Given("existe un alumno con nombre {string} y apellido {string}")
    public void existeUnAlumno(String nombre, String apellido) {
        Alumno alumno = new Alumno(null, nombre, apellido);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Alumno> request = new HttpEntity<>(alumno, headers);

        ResponseEntity<Alumno> response =
                restTemplate.postForEntity(baseUrl(), request, Alumno.class);
        assertEquals(HttpStatus.OK, response.getStatusCode());
        assertNotNull(response.getBody());
        lastCreatedId = response.getBody().getId();
    }

    // ─── WHEN ────────────────────────────────────────────────────────────────

    @When("consulto la lista de ep03")
    public void consultoLaListaDeAlumnos() {
        lastResponse = restTemplate.getForEntity(baseUrl(), List.class);
    }

    @When("creo un alumno con nombre {string} y apellido {string}")
    public void creoUnAlumno(String nombre, String apellido) {
        Alumno alumno = new Alumno(null, nombre, apellido);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Alumno> request = new HttpEntity<>(alumno, headers);

        lastResponse = restTemplate.postForEntity(baseUrl(), request, Alumno.class);
        if (lastResponse.getBody() instanceof Alumno a) {
            lastCreatedId = a.getId();
        }
    }

    @When("actualizo el alumno con nombre {string} y apellido {string}")
    public void actualizoElAlumno(String nombre, String apellido) {
        assertNotNull(lastCreatedId, "Debe existir un alumno creado previamente");
        Alumno alumno = new Alumno(null, nombre, apellido);
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        HttpEntity<Alumno> request = new HttpEntity<>(alumno, headers);

        lastResponse =
                restTemplate.exchange(
                        baseUrl() + "/" + lastCreatedId, HttpMethod.PUT, request, Alumno.class);
    }

    @When("elimino el alumno creado")
    public void eliminoElAlumnoCreado() {
        assertNotNull(lastCreatedId, "Debe existir un alumno creado previamente");
        lastResponse =
                restTemplate.exchange(
                        baseUrl() + "/" + lastCreatedId,
                        HttpMethod.DELETE,
                        HttpEntity.EMPTY,
                        Void.class);
    }

    @When("exporto los ep03 a CSV")
    public void exportoLosAlumnosACSV() {
        lastResponse = restTemplate.getForEntity(baseUrl() + "/export", String.class);
    }

    @When("importo el CSV {string}")
    public void importoElCSV(String csv) {
        String csvContent = csv.replace("\\n", "\n");
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.TEXT_PLAIN);
        HttpEntity<String> request = new HttpEntity<>(csvContent, headers);

        lastResponse = restTemplate.postForEntity(baseUrl() + "/import", request, Void.class);
    }

    // ─── THEN / AND ──────────────────────────────────────────────────────────

    @Then("la respuesta tiene codigo {int}")
    public void laRespuestaTieneCodigo(int codigo) {
        assertNotNull(lastResponse, "Debe haber una respuesta");
        assertEquals(codigo, lastResponse.getStatusCode().value());
    }

    @And("la lista de ep03 esta vacia")
    public void laListaDeAlumnosEstaVacia() {
        List<?> body = (List<?>) lastResponse.getBody();
        assertNotNull(body);
        assertTrue(body.isEmpty(), "La lista debe estar vacia");
    }

    @And("la lista contiene al menos {int} alumno")
    public void laListaContieneAlMenos(int cantidad) {
        List<?> body = (List<?>) lastResponse.getBody();
        assertNotNull(body);
        assertTrue(
                body.size() >= cantidad,
                "La lista debe tener al menos " + cantidad + " elemento(s)");
    }

    @And("el alumno retornado tiene nombre {string} y apellido {string}")
    public void elAlumnoRetornadoTiene(String nombre, String apellido) {
        Alumno alumno = objectMapper.convertValue(lastResponse.getBody(), Alumno.class);
        assertNotNull(alumno);
        assertEquals(nombre, alumno.getNombre());
        assertEquals(apellido, alumno.getApellido());
    }

    @And("el CSV contiene {string}")
    public void elCSVContiene(String fragmento) {
        String body = (String) lastResponse.getBody();
        assertNotNull(body);
        assertTrue(
                body.contains(fragmento),
                "El CSV debe contener: " + fragmento + "\nCSV actual: " + body);
    }
}
