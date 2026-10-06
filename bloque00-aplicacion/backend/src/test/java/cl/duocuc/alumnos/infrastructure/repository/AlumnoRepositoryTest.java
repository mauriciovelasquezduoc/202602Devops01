package cl.duocuc.ep03.infrastructure.repository;

import static org.junit.jupiter.api.Assertions.*;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;

import cl.duocuc.ep03.infrastructure.entity.AlumnoEntity;

@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.ANY)
class AlumnoRepositoryTest {

    @Autowired private TestEntityManager em;

    @Autowired private AlumnoRepository repo;

    @Test
    void save_persisteYRetornaConId() {
        AlumnoEntity alumno = new AlumnoEntity(null, "Juan", "Perez");

        AlumnoEntity saved = repo.save(alumno);

        assertNotNull(saved.getId());
        assertEquals("Juan", saved.getNombre());
        assertEquals("Perez", saved.getApellido());
    }

    @Test
    void findAll_retornaListaConTodosLosAlumnos() {
        em.persist(new AlumnoEntity(null, "Ana", "Lopez"));
        em.persist(new AlumnoEntity(null, "Carlos", "Soto"));
        em.flush();

        List<AlumnoEntity> result = repo.findAll();

        assertTrue(result.size() >= 2);
    }

    @Test
    void findById_retornaAlumnoCuandoExiste() {
        AlumnoEntity saved = em.persist(new AlumnoEntity(null, "Maria", "Gonzalez"));
        em.flush();

        Optional<AlumnoEntity> result = repo.findById(saved.getId());

        assertTrue(result.isPresent());
        assertEquals("Maria", result.get().getNombre());
    }

    @Test
    void findById_retornaVacioCuandoNoExiste() {
        Optional<AlumnoEntity> result = repo.findById(999L);

        assertFalse(result.isPresent());
    }

    @Test
    void deleteById_eliminaElAlumno() {
        AlumnoEntity saved = em.persist(new AlumnoEntity(null, "Luis", "Mora"));
        em.flush();
        Long id = saved.getId();

        repo.deleteById(id);
        em.flush();

        Optional<AlumnoEntity> result = repo.findById(id);
        assertFalse(result.isPresent());
    }

    @Test
    void save_actualizaNombreExistente() {
        AlumnoEntity saved = em.persist(new AlumnoEntity(null, "Pedro", "Diaz"));
        em.flush();

        saved.setNombre("Pedro Actualizado");
        repo.save(saved);
        em.flush();
        em.clear();

        AlumnoEntity updated = repo.findById(saved.getId()).orElseThrow();
        assertEquals("Pedro Actualizado", updated.getNombre());
    }
}
