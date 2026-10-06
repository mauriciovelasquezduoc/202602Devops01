import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "POST /ep03 crea un alumno y retorna el objeto con id"

    request {
        method POST()
        url '/ep03'
        headers {
            contentType applicationJson()
        }
        body([
            nombre  : "Juan",
            apellido: "Perez"
        ])
    }

    response {
        status OK()
        headers {
            contentType applicationJson()
        }
        body([
            id      : $(producer(anyPositiveInt()), consumer(1)),
            nombre  : "Juan",
            apellido: "Perez"
        ])
    }
}
