export default new class VidnestExtension {
  async single(args, options) {
    const fetch = args.fetch;
    const anilistId = args.anilistId;
    const episode = args.episode;
    
    const results = [];
    const providers = ["hianime", "animepahe"];
    const types = ["sub", "dub"];
    
    const _VIDNEST_ALPHA = "RB0fpH8ZEyVLkv7c2i6MAJ5u3IKFDxlS1NTsnGaqmXYdUrtzjwObCgQP94hoeW+/=";

    function decodeVidnest(data) {
      const alpha = _VIDNEST_ALPHA;
      const table = {};
      for (let idx = 0; idx < alpha.length; idx++) {
        table[alpha[idx]] = idx;
      }
      const result = [];
      let i = 0;
      while (i < data.length) {
        let chunk = data.slice(i, i + 4);
        while (chunk.length < 4) {
          chunk += "=";
        }
        i += 4;

        const indices = [];
        for (let cIdx = 0; cIdx < chunk.length; cIdx++) {
          const char = chunk[cIdx];
          indices.push(table[char] !== undefined ? table[char] : 64);
        }
        const [l0, l1, l2, l3] = indices;

        result.push((l0 << 2) | (l1 >> 4));
        if (l2 !== 64) {
          result.push(((l1 & 15) << 4) | (l2 >> 2));
        }
        if (l3 !== 64) {
          result.push(((l2 & 3) << 6) | l3);
        }
      }
      
      let str = "";
      for (let idx = 0; idx < result.length; idx++) {
        str += String.fromCharCode(result[idx]);
      }
      try {
        return decodeURIComponent(escape(str));
      } catch (e) {
        return str;
      }
    }
    
    for (var pIdx = 0; pIdx < providers.length; pIdx++) {
      var provider = providers[pIdx];
      for (var tIdx = 0; tIdx < types.length; tIdx++) {
        var type = types[tIdx];
        try {
          const url = "https://new.vidnest.fun/" + provider + "/" + anilistId + "/" + episode + "/1/" + type;
          const response = await fetch(url, {
            headers: {
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
              "Origin": "https://vidnest.fun",
              "Referer": "https://vidnest.fun/"
            }
          });
          
          if (response.status === 200) {
            const payload = JSON.parse(response.body);
            if (payload.encrypted) {
              const decrypted = decodeVidnest(payload.data);
              const data = JSON.parse(decrypted);
              if (data.success && data.sources && data.sources.length > 0) {
                const subTracks = [];
                if (data.tracks && data.tracks.length > 0) {
                  for (var sIdx = 0; sIdx < data.tracks.length; sIdx++) {
                    var track = data.tracks[sIdx];
                    subTracks.push({
                      url: track.file,
                      label: track.label || "Subtitle",
                      default: track.default || false
                    });
                  }
                }
                
                results.push({
                  name: "Vidnest [" + type.toUpperCase() + "] [" + provider.toUpperCase() + "]",
                  quality: "Auto",
                  url: data.sources[0].file,
                  headers: {
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                    "Origin": "https://vidnest.fun",
                    "Referer": "https://vidnest.fun/"
                  },
                  subtitles: subTracks,
                  intro: data.intro || null,
                  outro: data.outro || null
                });
              }
            }
          }
        } catch(e) {}
      }
    }
    return results;
  }
}
