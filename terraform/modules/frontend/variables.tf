variable "name" {
  description = "Name prefix (<project>-<environment>)."
  type        = string
}

variable "domain_name" {
  description = "Custom FQDN for the SPA (e.g. app.example.com). Empty ⇒ serve on the default *.cloudfront.net URL (no ACM/Route53)."
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 hosted zone for the ACM validation + alias record. Only needed with a custom domain_name."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "Attach a WAFv2 web ACL (AWS managed common rules + rate limit) to the distribution."
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "WAF rate-based rule limit (requests per 5-min per IP)."
  type        = number
  default     = 2000
}

variable "price_class" {
  description = "CloudFront price class (PriceClass_100 = NA+EU, cheapest)."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
