{#
  Use the custom schema name as is (raw, staging, intermediate, marts...)
  instead of dbt's default "<target_schema>_<custom>". Same layout locally and on Snowflake.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
