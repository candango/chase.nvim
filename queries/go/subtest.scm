(call_expression
    function: (selector_expression
        operand: (identifier) @t
        field: (field_identifier) @method
        (#eq? @t "t")
        (#eq? @method "Run"))
    arguments: (argument_list
        (interpreted_string_literal
           (interpreted_string_literal_content) @subtest.name) 
        (func_literal
            parameters: (parameter_list
                (parameter_declaration
                    type: (pointer_type
                        (qualified_type
                            package: (package_identifier) @pkg
                            name: (type_identifier) @type))))
            )) @call_exp
    (#eq? @pkg "testing")
    (#eq? @type "T"))
