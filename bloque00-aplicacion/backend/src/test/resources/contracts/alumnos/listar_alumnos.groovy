import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "GET /ep03 retorna lista vacía cuando no hay ep03"

    request {
        method GET()
        url '/ep03'
    }

    response {
        status OK()
        headers {
            contentType applicationJson()
        }
        body([])
    }
}
