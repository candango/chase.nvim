; Capture module definitions: mod_name -> source_path
(variable_declaration
  (identifier) @mod.name
  (call_expression
    function: (field_expression member: (identifier) @func (#eq? @func "createModule"))
    (anonymous_struct_initializer
      (initializer_list
        (assignment_expression
          left: (field_expression member: (identifier) @root_label (#eq? @root_label "root_source_file"))
          right: (call_expression
            function: (field_expression member: (identifier) @path_func (#eq? @path_func "path"))
            (string (string_content) @mod.path)))))))

; Capture executable definitions: exe_name -> [direct_path | mod_ref]
(call_expression
  function: (field_expression member: (identifier) @func (#eq? @func "addExecutable"))
  (anonymous_struct_initializer
    (initializer_list
      (assignment_expression
        left: (field_expression member: (identifier) @name_label (#eq? @name_label "name"))
        right: (string (string_content) @exe.name))
      (assignment_expression
        left: (field_expression member: (identifier) @root_label (#any-of? @root_label "root_source_file" "root_module"))
        right: [
          (call_expression
            function: (field_expression member: (identifier) @path_func (#eq? @path_func "path"))
            (string (string_content) @exe.path))
          (identifier) @exe.mod_ref
        ]))))
