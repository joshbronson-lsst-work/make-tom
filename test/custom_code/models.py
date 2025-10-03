from django.db import models
from tom_targets.models import Target

class TargetLabel(models.Model):
    target = models.ForeignKey(
        Target,
        on_delete=models.CASCADE,
        related_name='labels',
    )
    text = models.CharField(max_length=256)
