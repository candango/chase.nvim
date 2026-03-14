(class_definition 
    name: (identifier) @class.name
    (#match? @class.name "TestCase$")
    body: (block
        [
            (function_definition
                name: (identifier) @method.name
                (#match? @method.name "^test_")
            )
            (decorated_definition
                (function_definition
                    name: (identifier) @method.name
                    (#match? @method.name "^test_")
                )
            )
        ] @func.definition
    )
) 
