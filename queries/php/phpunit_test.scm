(class_declaration
    name: (name) @class.name) @class.def
(method_declaration
    (visibility_modifier) @vis
    name: (name) @method.name
    (#match? @method.name "^test")
    (#eq? @vis "public")) @method.def
