(class_declaration
    name: (identifier) @class.name) @class.def
(method_declaration
    (modifiers
        (marker_annotation
            name: (identifier) @annotation
            (#eq? @annotation "Test")))
    name: (identifier) @method.name) @method.def
