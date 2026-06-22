import 'package:flutter/material.dart';

/// A predefined surveillance preset that pre-fills the agent composer with a
/// sensible name and natural-language rule. Users can tweak the rule after
/// applying a template.
class AgentTemplate {
  const AgentTemplate({
    required this.label,
    required this.icon,
    required this.description,
    required this.name,
    required this.rule,
  });

  final String label;
  final IconData icon;
  final String description;
  final String name;
  final String rule;
}

const List<AgentTemplate> kAgentTemplates = [
  AgentTemplate(
    label: 'Pet Watch',
    icon: Icons.pets_outlined,
    description: 'Keep pets out of off-limits areas',
    name: 'Pet Watch',
    rule:
        'Alert me if a dog or cat jumps on the kitchen counter or enters a '
        'room marked off-limits.',
  ),
  AgentTemplate(
    label: 'Baby Care',
    icon: Icons.child_friendly_outlined,
    description: 'Watch the nursery for the little one',
    name: 'Baby Care',
    rule:
        'Alert me if the baby is standing or climbing in the crib, or if '
        'someone other than a known caregiver enters the nursery.',
  ),
  AgentTemplate(
    label: 'Abnormal Alert',
    icon: Icons.crisis_alert_outlined,
    description: 'Flag anything unusual',
    name: 'Abnormal Activity',
    rule:
        'Alert me if you detect abnormal or unusual activity such as a fall, '
        'a person loitering, or unexpected people during the night.',
  ),
  AgentTemplate(
    label: 'Front Door',
    icon: Icons.door_front_door_outlined,
    description: 'Visitors, loiterers and packages',
    name: 'Front Door Watch',
    rule:
        'Alert me if a person lingers near the front door after 10 PM, or if '
        'a package is delivered or taken from the porch.',
  ),
  AgentTemplate(
    label: 'Perimeter',
    icon: Icons.fence_outlined,
    description: 'Intrusion across a boundary',
    name: 'Perimeter Guard',
    rule:
        'Alert me if a person crosses the backyard fence line or opens the '
        'side gate.',
  ),
  AgentTemplate(
    label: 'Fire & Smoke',
    icon: Icons.local_fire_department_outlined,
    description: 'Detect smoke or flames early',
    name: 'Fire & Smoke Watch',
    rule:
        'Alert me immediately if you detect smoke, flames, or other signs of '
        'fire.',
  ),
];
