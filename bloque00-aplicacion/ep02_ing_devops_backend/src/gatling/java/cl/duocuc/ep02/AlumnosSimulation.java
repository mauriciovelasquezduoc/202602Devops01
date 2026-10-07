package cl.duocuc.ep02;

import static io.gatling.javaapi.core.CoreDsl.*;
import static io.gatling.javaapi.http.HttpDsl.*;

import io.gatling.javaapi.core.ChainBuilder;
import io.gatling.javaapi.core.ScenarioBuilder;
import io.gatling.javaapi.core.Simulation;
import io.gatling.javaapi.http.HttpProtocolBuilder;

/**
 * Prueba de carga (Gatling) para el backend ep02.
 *
 * <p>Requiere la aplicación en ejecución en http://localhost:8080. Uso:
 *
 * <pre>
 *   ./gradlew gatlingRun
 * </pre>
 */
public class AlumnosSimulation extends Simulation {

    private final HttpProtocolBuilder httpProtocol =
            http.baseUrl("http://localhost:8080")
                    .acceptHeader("application/json")
                    .contentTypeHeader("application/json");

    private final ChainBuilder health =
            exec(http("GET /actuator/health").get("/actuator/health").check(status().is(200)));

    private final ChainBuilder listar =
            exec(http("GET /ep02").get("/ep02").check(status().is(200)));

    private final ScenarioBuilder escenario =
            scenario("consultar alumnos")
                    .exec(health)
                    .pause(1)
                    .exec(listar)
                    .pause(1)
                    .exec(listar);

    public AlumnosSimulation() {
        super();
        setUp(escenario.injectOpen(atOnceUsers(10), rampUsers(20).during(10)))
                .protocols(httpProtocol);
    }
}
