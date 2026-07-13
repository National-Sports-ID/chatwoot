json.id @contact.id
json.has_email @contact.email.present?
json.has_name @contact.name.present?
json.has_phone_number @contact.phone_number.present?
json.identifier @contact.identifier
# NSID: expose the contact's own custom attributes so the widget can read them
# (e.g. ace_can_switch to decide whether to show the header "Switch Role" button).
json.custom_attributes @contact.custom_attributes
