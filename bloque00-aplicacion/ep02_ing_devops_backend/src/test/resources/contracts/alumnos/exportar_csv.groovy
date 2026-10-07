import org.springframework.cloud.contract.spec.Contract

Contract.make {
    description "GET /ep02/export retorna CSV con los ep02"

    request {
        method GET()
        url '/ep02/export'
    }

    response {
        status OK()
        body("")
    }
}
