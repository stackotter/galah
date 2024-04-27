import UtilityMacros

func collect<T, E: Foldable>(_ results: [Result<T, E>]) -> Result<[T], [E.Element]> {
    var values: [T] = []
    var errors: [E.Element] = []
    var success = true
    for result in results {
        switch result {
            case let .success(value):
                values.append(value)
            case let .failure(error):
                success = false
                error.fold(into: &errors)
        }
    }

    if success {
        return .success(values)
    } else {
        return .failure(errors)
    }
}

func collectResults<each T, E: Foldable>(
    _ results: repeat Result<each T, E>
) -> Result<(repeat each T), [E.Element]> {
    var errors: [E.Element] = []
    var success = true
    _ =
        (repeat (each results).mapError { error in
            success = false
            error.fold(into: &errors)
            return error
        })

    func value<U>(of result: Result<U, E>) -> U {
        try! result.get()
    }

    if success {
        let values: (repeat each T) = (repeat value(of: each results))
        return .success(values)
    } else {
        return .failure(errors)
    }
}

func invert<T, E: Error>(_ optionalResult: Result<T, E>?) -> Result<T?, E> {
    if let result = optionalResult {
        return result.map(Optional.some)
    } else {
        return .success(nil)
    }
}
