package cl.duocuc.ep03.application;

import java.util.List;

import org.springframework.stereotype.Service;

import cl.duocuc.ep03.domain.Alumno;
import cl.duocuc.ep03.infrastructure.mapper.AlumnoMapper;
import cl.duocuc.ep03.infrastructure.repository.AlumnoRepository;

@Service
public class AlumnoService {

    private final AlumnoRepository repo;

    public AlumnoService(AlumnoRepository repo) {
        this.repo = repo;
    }

    public List<Alumno> listar() {
        return repo.findAll().stream().map(AlumnoMapper::toDomain).toList();
    }

    public Alumno crear(Alumno a) {
        return AlumnoMapper.toDomain(repo.save(AlumnoMapper.toEntity(a)));
    }

    public Alumno actualizar(Long id, Alumno a) {
        a.setId(id);
        return crear(a);
    }

    public void eliminar(Long id) {
        repo.deleteById(id);
    }
}
