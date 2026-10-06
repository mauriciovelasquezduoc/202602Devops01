Feature: Gestion de ep03
  Como usuario del sistema
  Quiero gestionar ep03 mediante la API REST
  Para mantener el registro actualizado

  Background:
    Given la aplicacion esta en ejecucion

  Scenario: Listar ep03 cuando no hay ninguno
    When consulto la lista de ep03
    Then la respuesta tiene codigo 200
    And la lista de ep03 esta vacia

  Scenario: Crear un alumno exitosamente
    When creo un alumno con nombre "Juan" y apellido "Perez"
    Then la respuesta tiene codigo 200
    And el alumno retornado tiene nombre "Juan" y apellido "Perez"

  Scenario: Listar ep03 despues de crear uno
    Given existe un alumno con nombre "Ana" y apellido "Lopez"
    When consulto la lista de ep03
    Then la respuesta tiene codigo 200
    And la lista contiene al menos 1 alumno

  Scenario: Actualizar un alumno existente
    Given existe un alumno con nombre "Carlos" y apellido "Soto"
    When actualizo el alumno con nombre "Carlos" y apellido "Ramirez"
    Then la respuesta tiene codigo 200
    And el alumno retornado tiene nombre "Carlos" y apellido "Ramirez"

  Scenario: Eliminar un alumno existente
    Given existe un alumno con nombre "Luis" y apellido "Mora"
    When elimino el alumno creado
    Then la respuesta tiene codigo 200

  Scenario: Exportar ep03 a CSV
    Given existe un alumno con nombre "Maria" y apellido "Gonzalez"
    When exporto los ep03 a CSV
    Then la respuesta tiene codigo 200
    And el CSV contiene "Maria,Gonzalez"

  Scenario: Importar ep03 desde CSV
    When importo el CSV "Pedro,Diaz\nSofia,Ruiz"
    Then la respuesta tiene codigo 200
