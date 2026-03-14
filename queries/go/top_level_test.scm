(function_declaration
    name: (identifier) @func.name
    parameters: (parameter_list
        (parameter_declaration
            type: (pointer_type
                (qualified_type
                    package: (package_identifier) @pkg
                    name: (type_identifier) @type))))
    (#match? @func.name "^Test")
    (#eq? @pkg "testing")
    (#eq? @type "T")) @func.def
