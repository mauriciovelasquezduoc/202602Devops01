import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "GET /ep02 retorna lista vacía cuando no hay ep02"

    request {
        method GET()
        url '/ep02'
    }

    response {
        status OK()
        headers {
            contentType applicationJson()
        }
        body([])
    }
}
