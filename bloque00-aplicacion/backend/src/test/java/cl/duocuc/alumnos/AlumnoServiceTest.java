package cl.duocuc.ep03;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import cl.duocuc.ep03.application.AlumnoService;
import cl.duocuc.ep03.domain.Alumno;
import cl.duocuc.ep03.infrastructure.entity.AlumnoEntity;
import cl.duocuc.ep03.infrastructure.repository.AlumnoRepository;

class AlumnoServiceTest {

    private AlumnoRepository repo;
    private AlumnoService service;

    @BeforeEach
    void setUp() {
        repo = Mockito.mock(AlumnoRepository.class);
        service = new AlumnoService(repo);
    }

    @Test
    void listar_retornaListaMapeada() {
        AlumnoEntity entity = new AlumnoEntity(1L, "Juan", "Pérez");
        when(repo.findAll()).thenReturn(List.of(entity));

        List<Alumno> result = service.listar();

        assertEquals(1, result.size());
        assertEquals(1L, result.getFirst().getId());
        assertEquals("Juan", result.getFirst().getNombre());
        assertEquals("Pérez", result.getFirst().getApellido());
        verify(repo, times(1)).findAll();
    }

    @Test
    void listar_retornaListaVacia() {
        when(repo.findAll()).thenReturn(List.of());

        List<Alumno> result = service.listar();

        assertTrue(result.isEmpty());
    }

    @Test
    void crear_guardaYRetornaAlumno() {
        Alumno input = new Alumno(null, "Ana", "López");
        AlumnoEntity savedEntity = new AlumnoEntity(2L, "Ana", "López");
        when(repo.save(any(AlumnoEntity.class))).thenReturn(savedEntity);

        Alumno result = service.crear(input);

        assertEquals(2L, result.getId());
        assertEquals("Ana", result.getNombre());
        assertEquals("López", result.getApellido());
        verify(repo, times(1)).save(any(AlumnoEntity.class));
    }

    @Test
    void actualizar_seteaIdYGuarda() {
        Alumno input = new Alumno(null, "Carlos", "Soto");
        AlumnoEntity savedEntity = new AlumnoEntity(5L, "Carlos", "Soto");
        when(repo.save(any(AlumnoEntity.class))).thenReturn(savedEntity);

        Alumno result = service.actualizar(5L, input);

        // Verifica que el id fue seteado en el objeto antes de persistir
        assertEquals(5L, input.getId());
        assertEquals(5L, result.getId());
        assertEquals("Carlos", result.getNombre());
        verify(repo, times(1)).save(any(AlumnoEntity.class));
    }

    @Test
    void eliminar_llamaDeleteById() {
        doNothing().when(repo).deleteById(3L);

        service.eliminar(3L);

        verify(repo, times(1)).deleteById(3L);
    }
}
