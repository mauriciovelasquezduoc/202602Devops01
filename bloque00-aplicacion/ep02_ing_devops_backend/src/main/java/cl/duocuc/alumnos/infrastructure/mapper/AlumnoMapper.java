package cl.duocuc.ep02.infrastructure.mapper;

import cl.duocuc.ep02.domain.Alumno;
import cl.duocuc.ep02.infrastructure.entity.AlumnoEntity;

public final class AlumnoMapper {

    private AlumnoMapper() {
        // clase de utilidad, no instanciar
    }

    public static Alumno toDomain(AlumnoEntity e) {
        return new Alumno(e.getId(), e.getNombre(), e.getApellido());
    }

    public static AlumnoEntity toEntity(Alumno a) {
        return new AlumnoEntity(a.getId(), a.getNombre(), a.getApellido());
    }
}
