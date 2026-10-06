package cl.duocuc.ep03.infrastructure.mapper;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import org.junit.jupiter.api.Test;

import cl.duocuc.ep03.domain.Alumno;
import cl.duocuc.ep03.infrastructure.entity.AlumnoEntity;

class AlumnoMapperTest {

    @Test
    void toDomain_mapeaCorrectamente() {
        AlumnoEntity entity = new AlumnoEntity(1L, "María", "González");

        Alumno result = AlumnoMapper.toDomain(entity);

        assertEquals(1L, result.getId());
        assertEquals("María", result.getNombre());
        assertEquals("González", result.getApellido());
    }

    @Test
    void toEntity_mapeaCorrectamente() {
        Alumno alumno = new Alumno(2L, "Pedro", "Ramírez");

        AlumnoEntity result = AlumnoMapper.toEntity(alumno);

        assertEquals(2L, result.getId());
        assertEquals("Pedro", result.getNombre());
        assertEquals("Ramírez", result.getApellido());
    }

    @Test
    void toDomain_conCamposNulos() {
        AlumnoEntity entity = new AlumnoEntity(null, null, null);

        Alumno result = AlumnoMapper.toDomain(entity);

        assertNull(result.getId());
        assertNull(result.getNombre());
        assertNull(result.getApellido());
    }

    @Test
    void toEntity_conCamposNulos() {
        Alumno alumno = new Alumno(null, null, null);

        AlumnoEntity result = AlumnoMapper.toEntity(alumno);

        assertNull(result.getId());
        assertNull(result.getNombre());
        assertNull(result.getApellido());
    }
}
