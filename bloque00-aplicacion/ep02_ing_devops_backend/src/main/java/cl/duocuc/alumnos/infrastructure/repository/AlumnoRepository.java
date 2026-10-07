package cl.duocuc.ep02.infrastructure.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import cl.duocuc.ep02.infrastructure.entity.AlumnoEntity;

public interface AlumnoRepository extends JpaRepository<AlumnoEntity, Long> {}
