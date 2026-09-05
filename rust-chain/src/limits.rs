//! Validated emission policy. Keep the wire order in urotif_limits.f90 in sync.
#[derive(Clone, Debug)]
pub struct Limits(pub [i32; 11]);
pub const NAMES: [&str; 11] = [
    "nodes",
    "edges",
    "text",
    "output",
    "stack",
    "frames",
    "returns",
    "input-line",
    "input",
    "source",
    "work",
];
impl Default for Limits {
    fn default() -> Self {
        Self([
            32768, 32768, 524288, 262144, 2048, 64, 1024, 2048, 1048576, 1048576, 262144,
        ])
    }
}
impl Limits {
    pub fn checked(v: &[i32]) -> Result<Self, String> {
        if v.len() != 11 {
            return Err("expected 11 resource limits".into());
        }
        let low = [128, 32, 256, 64, 16, 1, 1, 1, 1, 64, 1];
        let high = [
            1048576, 4194304, 67108864, 33554432, 1048576, 1024, 1048576, 16777216, 67108864,
            8388608, 16777216,
        ];
        for i in 0..11 {
            if v[i] < low[i] || v[i] > high[i] {
                return Err(format!(
                    "{} limit must be {}..{}",
                    NAMES[i], low[i], high[i]
                ));
            }
        }
        Ok(Self(v.try_into().unwrap()))
    }
    pub fn rust_prelude(&self) -> String {
        let names = [
            "NC",
            "EC",
            "TC",
            "OC",
            "SC",
            "FC",
            "RC",
            "LC",
            "INPUT_CAP",
            "SOURCE_CAP",
            "WORK",
        ];
        names
            .iter()
            .zip(self.0)
            .map(|(name, n)| format!("const {name}:usize={n};\n"))
            .collect()
    }
    pub fn c_prelude(&self) -> String {
        let names = [
            "NC",
            "EC",
            "TC",
            "OC",
            "SC",
            "FC",
            "RC",
            "LC",
            "IC",
            "SOURCE_CAP",
            "WORK",
        ];
        names
            .iter()
            .zip(self.0)
            .map(|(name, n)| format!("#define {name} {n}\n"))
            .collect()
    }
    pub fn json(&self) -> String {
        format!(
            "{{{}}}",
            NAMES
                .iter()
                .zip(self.0)
                .map(|(name, n)| format!("\"{name}\":{n}"))
                .collect::<Vec<_>>()
                .join(",")
        )
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn checked_ranges() {
        assert!(Limits::checked(&Limits::default().0).is_ok());
        let mut a = Limits::default().0;
        a[4] = 0;
        assert!(Limits::checked(&a).is_err());
        a[4] = 8192;
        assert!(Limits::checked(&a).is_ok());
    }
}
