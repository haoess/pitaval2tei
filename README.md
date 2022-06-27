# pitaval2tei

Converts plain text files from the „Der neue Pitaval“ to TEI P5 XML

## Workflow

```bash
wget 'https://zenodo.org/record/6682897/files/Pitaval.zip
unzip Pitaval.zip
perl convert.pl --indir=Pitaval/ --outdir=xml
```
