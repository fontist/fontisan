---
title: Validation Profiles
---

# Validation Profiles

Fontisan includes 5 validation profiles for different use cases.

## indexability

Fast font discovery and indexing.

| Property | Value |
|----------|-------|
| Checks | 8 |
| Focus | Metadata-only |
| Speed | ~5x faster than production |

**Use Cases:**
- Font indexing systems
- Quick format verification
- Batch font discovery

```bash
fontisan validate font.ttf -t indexability
```

**Checks Performed:**
- Font format validity
- Basic table presence
- Name table readability
- Magic number validation

## usability

Font installation compatibility.

| Property | Value |
|----------|-------|
| Checks | 26 |
| Focus | macOS Font Book compatibility |
| Speed | Medium |

**Use Cases:**
- Font installation verification
- Desktop font deployment
- User-facing font distribution

```bash
fontisan validate font.ttf -t usability
```

**Checks Include:**
- All indexability checks
- Installation requirements
- Name table completeness
- Metrics validity

## production

Comprehensive production quality (default).

| Property | Value |
|----------|-------|
| Checks | 37 |
| Focus | OpenType spec compliance |
| Speed | Full |

**Use Cases:**
- Font production pipeline
- Quality assurance
- Font release validation

```bash
fontisan validate font.ttf -t production
# or
fontisan validate font.ttf
```

**Checks Include:**
- All usability checks
- OpenType specification compliance
- Cross-platform compatibility
- Advanced table validation

## web

Web embedding readiness.

| Property | Value |
|----------|-------|
| Checks | 18 |
| Focus | Web deployment |
| Speed | Medium |

**Use Cases:**
- Web font preparation
- CDN deployment
- Web performance optimization

```bash
fontisan validate font.ttf -t web
```

**Checks Include:**
- Required web tables
- Subset compatibility
- WOFF/WOFF2 readiness
- Performance optimization

## spec_compliance

Full OpenType specification compliance.

| Property | Value |
|----------|-------|
| Checks | Full |
| Focus | Detailed analysis |
| Speed | Slow |

**Use Cases:**
- Font specification audit
- Certification processes
- Technical documentation

```bash
fontisan validate font.ttf -t spec_compliance
```

**Checks Include:**
- All production checks
- Detailed specification analysis
- Edge case validation
- Comprehensive reporting

## Profile Comparison

| Feature | indexability | usability | production | web | spec |
|---------|-------------|-----------|------------|-----|------|
| Basic validation | ✓ | ✓ | ✓ | ✓ | ✓ |
| Installation checks | - | ✓ | ✓ | - | ✓ |
| Spec compliance | - | - | ✓ | - | ✓ |
| Web optimization | - | - | - | ✓ | - |
| Detailed analysis | - | - | - | - | ✓ |
| Speed | Fast | Medium | Full | Medium | Slow |

## Choosing a Profile

| Task | Recommended Profile |
|------|---------------------|
| Indexing fonts | `indexability` |
| Installing fonts | `usability` |
| Releasing fonts | `production` |
| Web deployment | `web` |
| Specification audit | `spec_compliance` |
| General use | `production` (default) |
