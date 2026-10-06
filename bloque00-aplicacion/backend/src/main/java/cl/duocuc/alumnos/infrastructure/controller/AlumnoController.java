package cl.duocuc.ep02.infrastructure.controller;

import java.util.List;
import java.util.stream.Collectors;

import org.springframework.web.bind.annotation.*;

import cl.duocuc.ep02.application.AlumnoService;
import cl.duocuc.ep02.domain.Alumno;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

@RestController
@RequestMapping("/ep02")
@Tag(name = "Alumnos", description = "Operaciones CRUD y CSV")
public class AlumnoController {

    private final AlumnoService service;

    public AlumnoController(AlumnoService service) {
        this.service = service;
    }

    @Operation(summary = "Listar ep02")
    @GetMapping
    public List<Alumno> listar() {
        return service.listar();
    }

    @Operation(summary = "Crear alumno")
    @PostMapping
    public Alumno crear(@RequestBody Alumno a) {
        return service.crear(a);
    }

    @Operation(summary = "Actualizar alumno")
    @PutMapping("/{id}")
    public Alumno actualizar(@PathVariable Long id, @RequestBody Alumno a) {
        return service.actualizar(id, a);
    }

    @Operation(summary = "Eliminar alumno")
    @DeleteMapping("/{id}")
    public void eliminar(@PathVariable Long id) {
        service.eliminar(id);
    }

    @Operation(summary = "Exportar ep02 a CSV")
    @GetMapping("/export")
    public String exportar() {
        return service.listar().stream()
                .map(a -> a.getNombre() + "," + a.getApellido())
                .collect(Collectors.joining("\n"));
    }

    @Operation(summary = "Importar ep02 desde CSV")
    @PostMapping("/import")
    public void importar(@RequestBody String csv) {
        java.util.Arrays.stream(csv.split("\n"))
                .map(line -> line.split(","))
                .filter(parts -> parts.length >= 2)
                .map(parts -> new Alumno(null, parts[0], parts[1]))
                .forEach(service::crear);
    }
}
