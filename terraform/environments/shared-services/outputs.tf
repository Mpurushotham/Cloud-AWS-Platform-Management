output "ecr_registry_url" { value = module.ecr.registry_id }
output "repository_urls" { value = module.ecr.repository_urls }
output "route53_zone_id" { value = module.route53.zone_id }
output "acm_certificate_arn" { value = module.acm.certificate_arn }
output "transit_gateway_id" { value = module.transit_gateway.tgw_id }
