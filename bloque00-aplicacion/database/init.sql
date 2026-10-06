-- ============================================================
-- Inicialización de la base de datos: ep03
-- Alineado con AlumnoEntity.java (tabla: ep03)
-- ============================================================

-- Crear tabla principal
CREATE TABLE IF NOT EXISTS ep03 (
    id        BIGSERIAL    PRIMARY KEY,
    nombre    VARCHAR(100) NOT NULL,
    apellido  VARCHAR(100) NOT NULL
);

-- Datos de ejemplo para desarrollo
INSERT INTO ep03 (nombre, apellido) VALUES
    ('Juan',    'Pérez'),
    ('Ana',     'López'),
    ('Carlos',  'Soto'),
    ('María',   'González'),
    ('Pedro',   'Ramírez'),
    ('Sofía',   'Muñoz'),
    ('Diego',   'Torres'),
    ('Valentina','Flores');
