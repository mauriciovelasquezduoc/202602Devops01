import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "GET /ep03/export retorna CSV con los ep03"

    request {
        method GET()
        url '/ep03/export'
    }

    response {
        status OK()
        body("")
    }
}
