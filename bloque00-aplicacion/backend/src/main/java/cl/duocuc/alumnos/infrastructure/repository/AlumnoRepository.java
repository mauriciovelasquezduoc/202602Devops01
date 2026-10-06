package cl.duocuc.ep03.infrastructure.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import cl.duocuc.ep03.infrastructure.entity.AlumnoEntity;

public interface AlumnoRepository extends JpaRepository<AlumnoEntity, Long> {}
